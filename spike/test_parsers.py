"""
test_parsers.py — parser 的回歸測試。

兩種測試：
  1. 合成 HTML：現在就能跑，鎖住解析邏輯本身
  2. fixture：你抓到真實頁面後自動生效，沒有 fixture 就 skip

學校改版的偵測方式：把新版 HTML 存成新 fixture，跑 pytest，看哪裡紅。
"""
from __future__ import annotations

from pathlib import Path

import pytest

from parsers import (
    MenuNode,
    clean,
    expand_grid,
    extract_tables,
    grid_text,
    hidden_field_value,
    is_empty_result,
    parse_callback_response,
    parse_grades,
    parse_menu,
    parse_timetable,
    parse_timetable_cell,
    pick_table,
    table_to_records,
    treeview_last_index,
    weekday_columns,
)

FIXTURES = Path(__file__).parent / "fixtures"


# ---------- 合成 HTML ----------

def test_clean_strips_fullwidth_and_nbsp():
    assert clean("　微積分\xa0\xa0 (一) ") == "微積分 (一)"


def test_extract_tables_flattens_gridview():
    html = """
    <table><tr><th>科目</th><th>學分</th></tr>
           <tr><td>微積分</td><td>3</td></tr></table>
    """
    tables = extract_tables(html)
    assert tables == [[["科目", "學分"], ["微積分", "3"]]]


def test_table_to_records_skips_ragged_rows():
    rows = [["科目", "學分"], ["微積分", "3"], ["合計"]]
    assert table_to_records(rows) == [{"科目": "微積分", "學分": "3"}]


def test_pick_table_matches_by_header_not_position():
    html = """
    <table><tr><td>公告</td></tr><tr><td>停電通知</td></tr></table>
    <table><tr><th>科目名稱</th><th>成績</th></tr>
           <tr><td>線性代數</td><td>92</td></tr></table>
    """
    rows = pick_table(html, "科目")
    assert rows is not None and rows[1] == ["線性代數", "92"]


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("微積分(一)\n王小明\n綜一01", ("微積分(一)", "王小明", "綜一01")),
        ("資料結構 / 陳大文 / 電資305", ("資料結構", "陳大文", "電資305")),
        ("體育", ("體育", "", "")),
        ("   ", ("", "", "")),
    ],
)
def test_parse_timetable_cell(raw, expected):
    assert parse_timetable_cell(raw) == expected


def test_parse_timetable_groups_slots_of_same_course():
    html = """
    <table>
      <tr><th>節次</th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th></tr>
      <tr><td>1</td><td>微積分<br>王小明<br>綜一01</td><td></td><td></td>
          <td>微積分<br>王小明<br>綜一01</td><td></td></tr>
      <tr><td>2</td><td>微積分<br>王小明<br>綜一01</td><td></td><td></td>
          <td></td><td></td></tr>
    </table>
    """
    courses = parse_timetable(html)
    assert len(courses) == 1
    c = courses[0]
    assert c.name == "微積分" and c.teacher == "王小明" and c.room == "綜一01"
    assert sorted(c.slots) == [(0, 1), (0, 2), (3, 1)]


def test_parse_timetable_ignores_non_timetable_tables():
    html = "<table><tr><th>公告</th></tr><tr><td>停課</td></tr></table>"
    assert parse_timetable(html) == []


def test_parse_grades_reads_by_header_name():
    html = """
    <table>
      <tr><th>科目名稱</th><th>學分</th><th>成績</th></tr>
      <tr><td>微積分(一)</td><td>3</td><td>85</td></tr>
      <tr><td>普通物理</td><td>4</td><td>78</td></tr>
    </table>
    """
    grades = parse_grades(html)
    assert [g.name for g in grades] == ["微積分(一)", "普通物理"]
    assert grades[0].credits == 3.0 and grades[0].score == "85"


def test_parse_grades_on_empty_page_returns_empty():
    assert parse_grades("<html><body>沒有資料</body></html>") == []


# ---------- 真實 fixture ----------

def _fixture(name: str) -> str:
    p = FIXTURES / name
    if not p.exists():
        pytest.skip(f"還沒有 {p.name}，先跑 login.py --save 抓一份")
    return p.read_text(encoding="utf-8")


def test_real_timetable_has_courses():
    courses = parse_timetable(_fixture("timetable.html"))
    assert courses, "真實課表解析出 0 門課 —— parser 要對著 HTML 調"
    assert all(c.name for c in courses)
    assert any(c.slots for c in courses), "沒抓到任何節次"


def test_real_grades_have_scores():
    grades = parse_grades(_fixture("grades.html"))
    assert grades, "真實成績頁解析出 0 筆"
    assert any(g.score for g in grades)


def test_login_page_still_has_expected_fields():
    """改版偵測：登入頁的欄位名如果變了，這裡會先紅。"""
    import json

    html = _fixture("login.html")
    cfg = json.loads((Path(__file__).parent / "selectors.json").read_text("utf-8"))
    login = cfg["login"]

    for key in ("username_field", "password_field"):
        name = login[key]
        if name.startswith("TODO"):
            pytest.skip("selectors.json 還沒填")
        assert f'name="{name}"' in html, f"{key}={name!r} 在登入頁上找不到了"


# ---------- TreeView 選單 ----------

def test_parse_menu_reads_populate_node_args():
    """
    選單的 JS 寫在 href="javascript:..." 屬性裡，引號被編碼成 &#39;，
    所以一定要先 HTML unescape 才切得出引數。
    """
    html = (
        "<a href=\"javascript:TreeView_PopulateNode(Menu_TreeView_Data,1,"
        "document.getElementById(&#39;n1&#39;),document.getElementById(&#39;t1&#39;),"
        # 真實頁面的 JS 字面值是 'NTOU\\STU'（兩個反斜線），unescape 後才會變一個
        r"null,&#39; &#39;,&#39;教務系統&#39;,&#39;NTOU\\STU&#39;,"
        "&#39;f&#39;,&#39;&#39;,&#39;tf&#39;)\">教務系統</a>"
    )
    nodes = parse_menu(html)
    assert len(nodes) == 1
    n = nodes[0]
    assert n.expandable
    assert n.text == "教務系統"
    assert n.path == r"NTOU\STU"
    assert n.parent_is_last == "tf"


def test_callback_param_matches_treeview_js():
    """
    參數格式抄自 WebResource.axd 的 TreeView_PopulateNode：
        index|lastIndex|databound+isChecked+parentIsLast|len(text)|text+len(datapath)|datapath+path
    這個字串錯一個字元，選單就展不開。
    """
    n = MenuNode(text="教務系統", index=1, path=r"NTOU\STU",
                 databound="f", datapath="", parent_is_last="tf")
    assert n.callback_param(19) == r"1|19|fftf|4|教務系統0|NTOU\STU"


def test_parse_menu_separates_leaf_links():
    html = '<a href="Application/PWD/PWD1020_.aspx">修改密碼</a>'
    nodes = parse_menu(html)
    assert len(nodes) == 1
    assert not nodes[0].expandable
    assert nodes[0].href == "Application/PWD/PWD1020_.aspx"


def test_parse_menu_ignores_javascript_hrefs_as_leaves():
    """javascript: 開頭的不是可直接 GET 的連結，不能混進 leaf。"""
    html = '<a href="javascript:TreeView_ToggleNode(x,0,y,\' \',z)">首頁</a>'
    assert [n for n in parse_menu(html) if n.href] == []


def test_real_menu_has_expandable_nodes():
    menu = FIXTURES / "MenuTree.aspx.html"
    if not menu.exists():
        pytest.skip("還沒有 MenuTree.aspx.html")
    html = menu.read_text(encoding="utf-8")

    nodes = parse_menu(html)
    expandable = [n for n in nodes if n.expandable]
    leaves = [n for n in nodes if n.href]

    # 每個節點在 href 和 onclick 各出現一次 —— 一定要去重
    indexes = [n.index for n in expandable]
    assert len(indexes) == len(set(indexes)), "節點沒去重"

    assert any(n.text == "教務系統" for n in expandable)
    assert treeview_last_index(html) > 0
    assert any("LogOut" in n.href for n in leaves)


def test_parse_callback_response_splits_three_parts():
    """
    格式抄自 TreeView_ProcessNodeData：
        <新的 lastIndex>|<新增的 ExpandState>|<HTML 片段>
    """
    r = parse_callback_response("22|cnnn|<div>子節點</div>")
    assert r is not None
    assert r.last_index == 22
    assert r.new_expand_state == "cnnn"
    assert r.html == "<div>子節點</div>"


def test_parse_callback_response_handles_empty_chunk():
    """伺服器說「這個節點沒有子項」時 chunk 是空的，但前兩段還在。"""
    r = parse_callback_response("19|nnnn|")
    assert r is not None and r.html == ""


def test_parse_callback_response_on_empty_payload():
    """完全空字串代表沒有子項 —— TreeView_ProcessNodeData 走 else 分支。"""
    assert parse_callback_response("") is None


@pytest.mark.parametrize("payload", ["沒有分隔符號", "22|只有一個分隔符號", "x|y|z"])
def test_parse_callback_response_rejects_malformed(payload):
    assert parse_callback_response(payload) is None


def test_html_chunk_may_contain_pipes():
    """HTML 片段裡本來就可能有 |，只能切前兩個分隔符號。"""
    r = parse_callback_response("5|c|<a title='a|b|c'>x</a>")
    assert r is not None and r.html == "<a title='a|b|c'>x</a>"


def test_hidden_field_value_reads_treeview_state():
    menu = FIXTURES / "MenuTree.aspx.html"
    if not menu.exists():
        pytest.skip("還沒有 MenuTree.aspx.html")
    html = menu.read_text(encoding="utf-8")
    expand = hidden_field_value(html, "Menu_TreeView_ExpandState")
    assert expand and set(expand) <= set("ecn"), f"ExpandState 格式怪怪的：{expand!r}"
    assert hidden_field_value(html, "Menu_TreeView_PopulateLog") == ""
    assert hidden_field_value(html, "根本不存在的欄位") == ""


# ---------- 課表格線 ----------

def test_expand_grid_repeats_rowspan_cell():
    from bs4 import BeautifulSoup
    html = """<table>
      <tr><td>1</td><td rowspan="3">連堂</td></tr>
      <tr><td>2</td></tr>
      <tr><td>3</td></tr>
    </table>"""
    g = expand_grid(BeautifulSoup(html, "lxml").find("table"))
    assert [r[0].get_text() for r in g] == ["1", "2", "3"]
    assert g[0][1] is g[1][1] is g[2][1], "跨列的格子要是同一個物件"


def test_expand_grid_repeats_colspan_cell():
    from bs4 import BeautifulSoup
    html = (
        '<table><tr><td colspan="3">跨三欄</td></tr>'
        "<tr><td>a</td><td>b</td><td>c</td></tr></table>"
    )
    g = expand_grid(BeautifulSoup(html, "lxml").find("table"))
    assert g[0][0] is g[0][1] is g[0][2]
    assert grid_text(g)[1] == ["a", "b", "c"]


def test_expand_grid_pads_ragged_rows():
    from bs4 import BeautifulSoup
    html = "<table><tr><td>a</td><td>b</td><td>c</td></tr><tr><td>d</td></tr></table>"
    g = expand_grid(BeautifulSoup(html, "lxml").find("table"))
    assert len({len(r) for r in g}) == 1, "每一列長度要一致"
    assert grid_text(g)[1] == ["d", "", ""]


@pytest.mark.parametrize("attr_value", ["0", "", "abc", "-2"])
def test_expand_grid_survives_bogus_span(attr_value):
    """學校的 HTML 不一定乾淨，rowspan="0" 或空字串不能讓整張表掛掉。"""
    from bs4 import BeautifulSoup
    html = f'<table><tr><td rowspan="{attr_value}">x</td><td>y</td></tr></table>'
    g = expand_grid(BeautifulSoup(html, "lxml").find("table"))
    assert grid_text(g)[0] == ["x", "y"]


def test_parse_timetable_expands_consecutive_periods():
    """
    連堂課用 rowspan 表示。舊版逐格讀只會抓到第一節，
    App 上就會顯示成一小時的課 —— 這是實際會害人遲到早退的錯。
    """
    html = """
    <table>
      <tr><th>節次</th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th></tr>
      <tr><td>3</td><td rowspan="2">計算機概論<br>李老師<br>電資201</td>
          <td></td><td></td><td></td><td></td></tr>
      <tr><td>4</td><td></td><td></td><td></td><td></td></tr>
    </table>
    """
    courses = parse_timetable(html)
    assert len(courses) == 1
    assert courses[0].slots == [(0, 3), (0, 4)], "連堂的兩節都要抓到"


def test_parse_timetable_handles_colspan_across_days():
    html = """
    <table>
      <tr><th>節次</th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th></tr>
      <tr><td>1</td><td colspan="2">週會</td><td></td><td></td><td></td></tr>
    </table>
    """
    courses = parse_timetable(html)
    assert courses[0].slots == [(0, 1), (1, 1)]


def test_parse_timetable_reads_weekday_order_from_header():
    """欄序不照「一二三四五」排也要對 —— 不能假設第 N 欄就是星期 N。"""
    html = """
    <table>
      <tr><th>五</th><th>四</th><th>三</th><th>二</th><th>一</th><th>節次</th></tr>
      <tr><td>物理</td><td></td><td></td><td></td><td></td><td>2</td></tr>
    </table>
    """
    courses = parse_timetable(html)
    assert courses[0].name == "物理"
    assert courses[0].slots == [(4, 2)], "第一欄的表頭是「五」，要對到週五"


def test_weekday_columns_ignores_period_labels():
    """「第一節」含「一」但不是星期欄。"""
    assert weekday_columns(["第一節", "一", "二", "三", "四", "五"]) == {
        1: 0, 2: 1, 3: 2, 4: 3, 5: 4
    }


def test_weekday_columns_accepts_prefixed_names():
    assert weekday_columns(["節次", "週一", "週二", "週三", "週四", "週五"]) == {
        1: 0, 2: 1, 3: 2, 4: 3, 5: 4
    }


def test_parse_timetable_does_not_duplicate_slots():
    """同一格因為 colspan 被讀到多次，slot 不能重複累加。"""
    html = """
    <table>
      <tr><th>節次</th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th></tr>
      <tr><td>1</td><td rowspan="2" colspan="2">專題</td><td></td><td></td><td></td></tr>
      <tr><td>2</td><td></td><td></td><td></td></tr>
    </table>
    """
    c = parse_timetable(html)[0]
    assert sorted(c.slots) == [(0, 1), (0, 2), (1, 1), (1, 2)]
    assert len(c.slots) == len(set(c.slots))


def test_empty_query_result_is_recognised():
    """
    查無資料時頁面結構完全正常、狀態碼 200，只有一行字不同。
    不認得的話會以為是 parser 壞了，然後去 debug 錯的東西。
    """
    assert is_empty_result("<td>查無符合資料!! There is no matching data</td>")
    assert is_empty_result("<td>There is no matching data for your query!!</td>")


def test_populated_result_is_not_empty():
    assert not is_empty_result("<table><tr><td>微積分</td></tr></table>")


def test_real_empty_result_fixture():
    p = FIXTURES / "Application_TKE_TKE22_TKE2240_01__QUERY_BTN1_115_1.html"
    if not p.exists():
        pytest.skip("還沒有 115-1 的查詢結果")
    assert is_empty_result(p.read_text(encoding="utf-8"))
