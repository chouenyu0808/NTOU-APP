"""
parsers.py — 純函式。輸入 HTML 字串，輸出資料類別。不碰網路、不碰檔案。

這是整個專案唯一會因為學校改版而爛掉的地方，所以刻意隔離：
  - 不 import ais
  - 不做 I/O
  - 每個函式都可以直接餵 fixture 做單元測試

學校改版時，你會先看到測試變紅，而不是先看到一星負評。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from html import unescape

from bs4 import BeautifulSoup

WS_RE = re.compile(r"[\s　]+")
# 常見教室代碼：綜一01、電資305、海工B12 之類
ROOM_RE = re.compile(r"[A-Za-z一-鿿]{1,6}[A-Za-z]?-?\d{2,4}[A-Za-z]?")
CREDIT_RE = re.compile(r"(\d+(?:\.\d+)?)\s*學分")

WEEKDAYS = ["一", "二", "三", "四", "五", "六", "日"]

# 課表解析的門檻值。全部是啟發式的猜測，不是規格 ——
# 拿到真實 fixture 之後要回來對，猜錯只會少顯示欄位，不該讓整張表掛掉。
TEACHER_NAME_MIN, TEACHER_NAME_MAX = 2, 8   # 「王小明」到「Christopher」之間
WEEKDAY_HEADER_MAX = 4                      # 「週一」「星期一」可以，「第一節課程」不行
MIN_WEEKDAY_COLUMNS = 4                     # 認得出四天以上才當成課表
MIN_TIMETABLE_ROWS = 2                      # 至少要有表頭 + 一列


def clean(text: str) -> str:
    """壓掉全形空白、&nbsp;、連續空白。WebForms 的表格塞滿這些。"""
    return WS_RE.sub(" ", text.replace("\xa0", " ")).strip()


# ---------- 通用 GridView 解析 ----------

def extract_tables(html: str) -> list[list[list[str]]]:
    """
    把頁面上每個 <table> 轉成 rows x cells 的純文字二維陣列。
    WebForms 的 GridView / DataGrid 都吃這招。
    """
    soup = BeautifulSoup(html, "lxml")
    tables = []
    for table in soup.find_all("table"):
        rows = []
        for tr in table.find_all("tr"):
            cells = [clean(td.get_text(" ")) for td in tr.find_all(["td", "th"])]
            if cells:
                rows.append(cells)
        if rows:
            tables.append(rows)
    return tables


def table_to_records(rows: list[list[str]], header_row: int = 0) -> list[dict[str, str]]:
    """第一列當表頭，其餘轉 dict。欄數不符的列直接跳過（通常是分頁列或合計列）。"""
    if len(rows) <= header_row:
        return []
    header = rows[header_row]
    out = []
    for row in rows[header_row + 1:]:
        if len(row) != len(header):
            continue
        # 長度上面檢查過了，strict=True 把這個不變量寫進程式碼
        out.append(dict(zip(header, row, strict=True)))
    return out


def pick_table(html: str, *must_contain: str) -> list[list[str]] | None:
    """
    挑出表頭同時含有這些字的表格。
    比 nth-child 選擇器耐改版 —— 學校加一個 <div> 不會害你抓錯表。
    """
    for rows in extract_tables(html):
        head = " ".join(rows[0])
        if all(k in head for k in must_contain):
            return rows
    return None


# ---------- 資料模型 ----------

@dataclass
class Course:
    name: str
    code: str = ""
    teacher: str = ""
    room: str = ""
    credits: float | None = None
    slots: list[tuple[int, int]] = field(default_factory=list)  # (weekday 0-6, period)

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "code": self.code,
            "teacher": self.teacher,
            "room": self.room,
            "credits": self.credits,
            "slots": [list(s) for s in self.slots],
        }


@dataclass
class Grade:
    name: str
    code: str = ""
    credits: float | None = None
    score: str = ""
    semester: str = ""


# ---------- 課表 ----------

def parse_timetable_cell(text: str) -> tuple[str, str, str]:
    """
    課表格子裡通常是「課名 / 老師 / 教室」擠在一起，用 <br> 分行。
    回傳 (課名, 老師, 教室)。抓不到就給空字串，不要 raise。

    刻意寫得寬鬆 —— 這裡猜錯只是少顯示一個欄位，不該讓整張課表掛掉。
    """
    parts = [clean(p) for p in re.split(r"[\n/｜|]+", text) if clean(p)]
    if not parts:
        return "", "", ""

    name = parts[0]
    room = ""
    teacher = ""

    for p in parts[1:]:
        if not room and ROOM_RE.fullmatch(p):
            room = p
        elif not teacher and TEACHER_NAME_MIN <= len(p) <= TEACHER_NAME_MAX:
            teacher = p

    return name, teacher, room


def weekday_columns(header: list[str]) -> dict[int, int]:
    """
    表頭文字 -> {欄索引: 星期索引}（0=週一）。

    用文字比對而不是假設「第一欄是節次、後面七欄依序是一到日」——
    有些課表把週六日放前面、有些沒有週日、有些節次欄在最右邊。

    「第一節」「第三節」這種會誤中「一」「三」，所以含「節」的欄位一律排除。
    """
    out: dict[int, int] = {}
    for col, text in enumerate(header):
        if not text or "節" in text or len(text) > WEEKDAY_HEADER_MAX:
            continue
        for wd, name in enumerate(WEEKDAYS):
            if name in text:
                out[col] = wd
                break
    return out


def parse_timetable(html: str) -> list[Course]:
    """
    抓課表。

    用 expand_grid() 攤平 rowspan / colspan —— 連堂課是用 rowspan 表示的，
    照位置逐格讀的話兩小時的課只會出現在第一節。

    節次欄不假設在第 0 欄，而是「表頭認不出是星期的那一欄」。
    """
    soup = BeautifulSoup(html, "lxml")

    for table in soup.find_all("table"):
        grid = expand_grid(table)
        if len(grid) < MIN_TIMETABLE_ROWS:
            continue

        header = [clean(c.get_text(" ")) if c is not None else "" for c in grid[0]]
        wd_cols = weekday_columns(header)
        if len(wd_cols) < MIN_WEEKDAY_COLUMNS:
            continue

        period_col = next(
            (i for i in range(len(header)) if i not in wd_cols), 0
        )

        courses: dict[str, Course] = {}
        for r in range(1, len(grid)):
            row = grid[r]
            period_cell = row[period_col] if period_col < len(row) else None
            period = _period_of(clean(period_cell.get_text(" "))) if period_cell else None

            for col, wd in wd_cols.items():
                if col >= len(row):
                    continue
                cell = row[col]
                if cell is None:
                    continue
                raw = cell.get_text("\n")
                if not clean(raw):
                    continue

                name, teacher, room = parse_timetable_cell(raw)
                if not name:
                    continue

                key = f"{name}|{teacher}"
                course = courses.setdefault(
                    key, Course(name=name, teacher=teacher, room=room)
                )
                if period is not None and (wd, period) not in course.slots:
                    course.slots.append((wd, period))

        if courses:
            for c in courses.values():
                c.slots.sort()
            return sorted(courses.values(),
                          key=lambda c: (c.slots[0] if c.slots else (99, 99), c.name))

    return []


def _period_of(text: str) -> int | None:
    """節次欄可能是 '1'、'第1節'、'A'、'08:10~09:00'。抓得到數字就用。"""
    m = re.search(r"\d+", text)
    return int(m.group()) if m else None


# ---------- 成績 ----------

def parse_grades(html: str) -> list[Grade]:
    """
    成績表。用表頭關鍵字找表，不用位置 —— 學校在旁邊多加一張表也不會抓錯。
    """
    rows = pick_table(html, "科目") or pick_table(html, "課程")
    if not rows:
        return []

    out = []
    for rec in table_to_records(rows):
        name = _first(rec, "科目名稱", "課程名稱", "科目", "課程")
        if not name:
            continue
        out.append(
            Grade(
                name=name,
                code=_first(rec, "科目代號", "課號", "選課代號"),
                credits=_to_float(_first(rec, "學分", "學分數")),
                score=_first(rec, "成績", "分數", "總成績"),
                semester=_first(rec, "學期", "修課學期"),
            )
        )
    return out


def _first(rec: dict[str, str], *keys: str) -> str:
    """表頭字串在不同頁面可能略有差異，給幾個候選。也接受部分比對。"""
    for k in keys:
        if k in rec:
            return rec[k]
    for k in keys:
        for actual, v in rec.items():
            if k in actual:
                return v
    return ""


def _to_float(text: str) -> float | None:
    m = re.search(r"\d+(?:\.\d+)?", text or "")
    return float(m.group()) if m else None


# ---------- ASP.NET TreeView 選單 ----------

@dataclass
class MenuNode:
    """
    選單節點。expandable 的要靠 callback 才拿得到子節點（延遲載入），
    leaf 的直接有 href 可以走。
    """
    text: str
    href: str = ""                 # leaf：可直接 GET 的路徑
    index: int | None = None       # expandable：TreeView 節點索引
    path: str = ""                 # expandable：節點值，例如 NTOU\STU
    databound: str = "f"
    datapath: str = ""
    parent_is_last: str = ""

    @property
    def expandable(self) -> bool:
        return self.index is not None

    def callback_param(self, last_index: int, is_checked: str = "f") -> str:
        """
        重建 TreeView_PopulateNode 送出的 __CALLBACKPARAM。

        格式抄自 WebResource.axd 裡的 TreeView_PopulateNode（不是猜的）：
            index|lastIndex|databound+isChecked+parentIsLast|len(text)|text+len(datapath)|datapath+path
        """
        return (
            f"{self.index}|{last_index}|"
            f"{self.databound}{is_checked}{self.parent_is_last}|"
            f"{len(self.text)}|{self.text}{len(self.datapath)}|"
            f"{self.datapath}{self.path}"
        )


_POPULATE_CALL = "TreeView_PopulateNode("

# 引數位置，對照 WebResource.axd 裡的函式簽章：
# TreeView_PopulateNode(data, index, node, selectNode, selectImageNode,
#                       lineType, text, path, databound, datapath, parentIsLast)
_ARG_INDEX, _ARG_TEXT, _ARG_PATH = 1, 6, 7
_ARG_DATABOUND, _ARG_DATAPATH, _ARG_PARENTLAST = 8, 9, 10


def _split_js_args(src: str, start: int) -> tuple[list[str], int] | None:
    """
    從 src[start] 這個 '(' 開始，切出頂層引數，回傳 (引數list, 收尾括號位置)。

    不用 regex 硬幹，因為引數裡有引號、逗號和跳脫字元
    （例如 'NTOU\\STU'），寫成一整條 regex 只會又醜又脆。
    """
    if start >= len(src) or src[start] != "(":
        return None

    args, buf = [], []
    depth, quote, i = 0, None, start

    while i < len(src):
        ch = src[i]
        if quote:
            if ch == "\\" and i + 1 < len(src):
                buf.append(src[i:i + 2])
                i += 2
                continue
            if ch == quote:
                quote = None
            buf.append(ch)
        elif ch in "'\"":
            quote = ch
            buf.append(ch)
        elif ch == "(":
            depth += 1
            if depth > 1:
                buf.append(ch)
        elif ch == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(buf).strip())
                return args, i
            buf.append(ch)
        elif ch == "," and depth == 1:
            args.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
        i += 1

    return None


def _js_literal(arg: str) -> str:
    r"""把 JS 字串字面值還原成實際值：'NTOU\\STU' -> NTOU\STU。"""
    if len(arg) >= 2 and arg[0] == arg[-1] and arg[0] in "'\"":  # noqa: PLR2004
        arg = arg[1:-1]
    return re.sub(r"\\(.)", r"\1", arg)


def parse_menu(html: str) -> list[MenuNode]:
    """
    從 MenuTree.aspx（或 callback 回傳的片段）解析選單節點。

    TreeView 是延遲載入的：初始 HTML 只有第一層，子節點要 callback 才拿得到。
    """
    nodes: list[MenuNode] = []
    seen: set[int] = set()

    # 這串 JS 是寫在 href="javascript:..." 屬性裡的，引號被編碼成 &#39;。
    # 不先解碼的話切出來的引數會連 &#39; 一起帶進去。
    # 同一個節點通常在 href 和 onclick 各出現一次，所以要按 index 去重。
    unescaped = unescape(html)

    pos = 0
    while (hit := unescaped.find(_POPULATE_CALL, pos)) != -1:
        open_paren = hit + len(_POPULATE_CALL) - 1
        parsed = _split_js_args(unescaped, open_paren)
        if parsed is None:
            pos = hit + len(_POPULATE_CALL)
            continue

        args, end = parsed
        pos = end + 1
        if len(args) <= _ARG_PARENTLAST:
            continue

        try:
            index = int(_js_literal(args[_ARG_INDEX]))
        except ValueError:
            continue
        if index in seen:
            continue
        seen.add(index)

        nodes.append(MenuNode(
            text=_js_literal(args[_ARG_TEXT]),
            index=index,
            path=_js_literal(args[_ARG_PATH]),
            databound=_js_literal(args[_ARG_DATABOUND]),
            datapath=_js_literal(args[_ARG_DATAPATH]),
            parent_is_last=_js_literal(args[_ARG_PARENTLAST]),
        ))

    soup = BeautifulSoup(html, "lxml")
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith("javascript:"):
            continue
        text = clean(a.get_text())
        if text:
            nodes.append(MenuNode(text=text, href=href))

    return nodes


def treeview_last_index(html: str) -> int:
    """Menu_TreeView_Data.lastIndex —— callback 參數要用。"""
    m = re.search(r"\.lastIndex\s*=\s*(\d+)", html)
    return int(m.group(1)) if m else 0


@dataclass
class CallbackResult:
    """TreeView callback 的回應拆解結果。"""
    last_index: int
    new_expand_state: str
    html: str


def parse_callback_response(payload: str) -> CallbackResult | None:
    """
    拆解 TreeView callback 的回應。格式抄自 TreeView_ProcessNodeData：

        <新的 lastIndex>|<新增的 ExpandState>|<HTML 片段>

    瀏覽器收到後做三件事，少一件下一層就展不開：
        data.lastIndex        = <新的 lastIndex>      （讀回應，不是自己算）
        expandState.value    += <新增的 ExpandState>  （累加）
        populateLog.value    += index + ","           （累加，由呼叫端負責）

    回傳 None 代表這個節點沒有子項（回應是空字串）。
    """
    if not payload:
        return None

    first = payload.find("|")
    if first == -1:
        return None
    second = payload.find("|", first + 1)
    if second == -1:
        return None

    try:
        last_index = int(payload[:first])
    except ValueError:
        return None

    return CallbackResult(
        last_index=last_index,
        new_expand_state=payload[first + 1:second],
        html=payload[second + 1:],
    )


def hidden_field_value(html: str, name: str) -> str:
    """抓某個 hidden input 的現值 —— TreeView 的狀態欄位要接力傳下去。"""
    soup = BeautifulSoup(html, "lxml")
    el = soup.find("input", {"name": name})
    return el.get("value", "") if el is not None else ""


# ---------- 表格格線（rowspan / colspan） ----------

def _span(cell, attr: str) -> int:
    """rowspan/colspan 可能是空字串、0、或非數字。一律當成 1。"""
    try:
        n = int((cell.get(attr) or "1").strip())
    except (ValueError, AttributeError):
        return 1
    return max(n, 1)


def expand_grid(table) -> list[list]:
    """
    把含 rowspan / colspan 的 <table> 攤平成規則的二維陣列。

    被跨欄/跨列涵蓋的每一格都放**同一個** cell 物件，所以呼叫端可以用
    `is` 判斷「這幾格是同一堂課」。

    課表非做不可：連堂課是用 rowspan 表示的，照位置逐格讀的話
    兩小時的課只會出現在第一節，App 上的課表就是錯的。
    """
    grid: list[list] = []

    def ensure_row(r: int) -> list:
        while len(grid) <= r:
            grid.append([])
        return grid[r]

    def place(r: int, c: int, cell) -> None:
        row = ensure_row(r)
        while len(row) <= c:
            row.append(None)
        row[c] = cell

    for r, tr in enumerate(table.find_all("tr")):
        cells = tr.find_all(["td", "th"], recursive=False) or tr.find_all(["td", "th"])
        row = ensure_row(r)
        col = 0
        for cell in cells:
            while col < len(row) and row[col] is not None:
                col += 1          # 這格已經被上面的 rowspan 佔住了
            rs, cs = _span(cell, "rowspan"), _span(cell, "colspan")
            for dr in range(rs):
                for dc in range(cs):
                    place(r + dr, col + dc, cell)
            col += cs

    width = max((len(r) for r in grid), default=0)
    for row in grid:
        row.extend([None] * (width - len(row)))
    return grid


def grid_text(grid: list[list]) -> list[list[str]]:
    """格線轉純文字，方便肉眼比對。跨格的內容會在每一格重複出現。"""
    return [[clean(c.get_text(" ")) if c is not None else "" for c in row]
            for row in grid]
