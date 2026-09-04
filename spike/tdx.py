"""
tdx.py — 對交通部 TDX 打一次真實請求，把回應的**實際形狀**吐出來。

這支腳本的重點不是抓資料，是回答一個問題：
**`app/lib/src/transit/transit_repository.dart` 裡那些候選欄位名，哪一個是真的？**

會這樣寫是因為 TDX 的公開 swagger 在 schema 那一段是截斷的，而沒有金鑰
打不到真實回應。所以 Dart 那邊每個欄位都準備了好幾個候選名字
（`EstimateTime` / `EstimatedTime`、`RouteName` 是字串還是 `{Zh_tw: ...}`）。
賭一個名字的話，猜錯的下場是解析出一片空白 —— 而畫面上「解析失敗」跟
「這站現在沒車」長得一模一樣，沒有人會發現。

跑完它會告訴你：命中的是哪一個、有沒有哪個欄位一個都沒命中。

## 先拿金鑰

1. 到 https://tdx.transportdata.tw/ 註冊會員（免費）。帳號審核**最多三個工作日**。
2. 會員中心 → 「資料服務」→ 取得 Client Id 與 Client Secret。
3. 複製 `tdx.local.json.example` 成 `tdx.local.json`（repo 根目錄）並填進去。
   那個檔案在 `.gitignore` 裡，不會進版控，而且 `flutter build` 的
   `--dart-define-from-file` 讀的是同一份 —— 設一次，兩邊都有。

臨時想換一把金鑰跑的話，環境變數會蓋過檔案：

    $env:TDX_CLIENT_ID = "..."
    $env:TDX_CLIENT_SECRET = "..."

## 用法

    python tdx.py                 # 全部跑一遍
    python tdx.py --save          # 順便把回應存成 fixture
    python tdx.py --stop 海大體育館  # 只查一站
"""

from __future__ import annotations

import _console  # noqa: F401  # 必須最先 import

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

import requests

HERE = Path(__file__).parent
CONFIG = HERE.parent / "app" / "assets" / "transit.json"
FIXTURES = HERE / "fixtures" / "tdx"

# 金鑰檔。**不進版控**（見 .gitignore）。跟 flutter build 的
# --dart-define-from-file 讀的是同一份，所以只要維護一份。
KEY_FILE = HERE.parent / "tdx.local.json"

TIMEOUT = 20
HTTP_OK = 200


# --------------------------------------------------------------- 認證


def read_keys() -> tuple[str, str]:
    """拿金鑰：環境變數優先，其次是 tdx.local.json。

    **環境變數優先是刻意的** —— 臨時想用另一把金鑰跑一次的時候，
    在那個視窗設一下就好，不用去動檔案再改回來。

    檔案那條路是為了「每次重開機都要重設一次環境變數」這件事。它跟
    flutter build 的 --dart-define-from-file 讀的是同一份，所以只要維護一份。
    """
    env_id = os.environ.get("TDX_CLIENT_ID", "")
    env_secret = os.environ.get("TDX_CLIENT_SECRET", "")
    if env_id and env_secret:
        return env_id, env_secret

    if not KEY_FILE.exists():
        return env_id, env_secret
    try:
        data = json.loads(KEY_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"[!] {KEY_FILE.name} 讀不到或格式不對，先當成沒有金鑰。")
        return env_id, env_secret

    # 檔案裡的 _comment 那些是寫給人看的，不是金鑰。
    return (
        env_id or str(data.get("TDX_CLIENT_ID", "")),
        env_secret or str(data.get("TDX_CLIENT_SECRET", "")),
    )


def get_token(config: dict[str, Any]) -> str:
    """換一張 access token。

    token 端點**每個 IP 每分鐘只准打 20 次**，所以不要把這支腳本寫進迴圈裡。
    """
    client_id, client_secret = read_keys()
    if not client_id or not client_secret:
        print("找不到金鑰。兩種擺法擇一：")
        print()
        print(f"  1. 複製 {KEY_FILE.name}.example 成 {KEY_FILE.name} 並填進去")
        print("     （設一次就好，重開機也還在，flutter build 也讀同一份）")
        print()
        print("  2. 環境變數（這個視窗關掉就沒了）：")
        print('     $env:TDX_CLIENT_ID = "..."')
        print('     $env:TDX_CLIENT_SECRET = "..."')
        sys.exit(1)

    res = requests.post(
        config["auth"]["token_url"],
        data={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        },
        headers={"content-type": "application/x-www-form-urlencoded"},
        timeout=TIMEOUT,
    )
    if res.status_code != HTTP_OK:
        # **不要印 res.text。** 失敗的回應有可能把送出的參數回吐，而這個請求
        # 的 body 就是 client_secret 本人。只挑 OAuth 規格定義的那兩個欄位 ——
        # 它們講的是「哪裡錯了」，不含憑證。
        detail = ""
        try:
            body = res.json()
            picked = [str(body[k]) for k in ("error", "error_description") if k in body]
            detail = "：" + " / ".join(picked) if picked else ""
        except ValueError:
            pass
        print(f"換 token 失敗：HTTP {res.status_code}{detail}")
        if res.status_code in (400, 401):
            # 這兩個幾乎都是同一件事，而錯誤碼本身完全看不出來。
            print("  金鑰不對。確認環境變數裡是真的 client id / secret，")
            print("  不是複製指令時留下的佔位符（長度：", end="")
            print(f"id={len(client_id)} secret={len(client_secret)}）")
        sys.exit(1)

    body = res.json()
    ttl = body.get("expires_in", 0)
    print(f"拿到 token，有效 {ttl} 秒（{ttl / 3600:.0f} 小時）")
    return body["access_token"]


def call(token: str, config: dict[str, Any], path: str, **params: str) -> Any:
    """打一個資料端點。回傳解析後的 JSON（原樣，不做 unwrap）。"""
    url = config["api"]["base_url"] + path
    res = requests.get(
        url,
        params={"$format": "JSON", **params},
        headers={"authorization": f"Bearer {token}"},
        timeout=TIMEOUT,
    )
    print(f"  HTTP {res.status_code}  {path}")
    if res.status_code != HTTP_OK:
        print(f"  回應：{res.text[:300]}")
        return None
    return res.json()


# ------------------------------------------------------- 形狀報告


def unwrap(data: Any) -> tuple[list[dict], str]:
    """挖出那個陣列，順便回報它是怎麼包的。

    跟 Dart 的 `TdxClient.unwrap` 同一套邏輯 —— 這裡多回傳一個「包在哪」，
    是為了印出來給人看。
    """
    if isinstance(data, list):
        return [r for r in data if isinstance(r, dict)], "裸陣列（v2 的形狀）"
    if isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, list):
                rows = [r for r in value if isinstance(r, dict)]
                return rows, f"包在 {key!r} 底下（v3 的形狀）"
    return [], "認不得的形狀"


def describe(rows: list[dict], shape: str, candidates: dict[str, list[str]]) -> None:
    """印出實際欄位名，並比對 Dart 那邊的候選清單。

    **掃過每一筆，不是只看第一筆。** 這支腳本原本只看 `rows[0]`，結果第一次
    跑真實資料就報了假警報：深夜抓下來的 15 筆公車裡有 14 筆是「末班已過」，
    而 TDX **在沒有車的那幾筆裡根本不放 `EstimateTime` 這個 key**。第一筆
    剛好是沒車的，於是它印出「候選一個都沒命中」，而那個欄位其實好好的。

    選擇性欄位在這份 API 裡是常態而不是例外，所以下面除了命中與否，還會印出
    「幾筆裡有幾筆帶著它」—— 那個比例本身就是資訊。
    """
    print(f"  形狀：{shape}，{len(rows)} 筆")
    if not rows:
        print("  （沒有資料 —— 可能是這個時段真的沒車，換個時間再跑一次）")
        return

    n = len(rows)
    seen: dict[str, int] = {}
    for r in rows:
        for k in r:
            seen[k] = seen.get(k, 0) + 1

    print(f"  實際欄位：{', '.join(sorted(seen))}")
    optional = {k: c for k, c in seen.items() if c != n}
    if optional:
        pretty = ", ".join(f"{k}({c}/{n})" for k, c in sorted(optional.items()))
        print(f"  選擇性欄位（不是每筆都有）：{pretty}")

    for label, names in candidates.items():
        hit = next((x for x in names if x in seen), None)
        if hit is None:
            print(f"  [!] {label}：候選 {names} 一個都沒命中")
            continue
        # 拿一筆真的帶著這個欄位的來看型別，不是拿第一筆。
        value = next(r[hit] for r in rows if hit in r)
        kind = "巢狀多語系物件" if isinstance(value, dict) else type(value).__name__
        if isinstance(value, dict):
            extra = f" -> {value}"
        elif isinstance(value, list):
            # **不要把整包印出來。** 站序是 68 個站牌的陣列，照印會把整份
            # 輸出淹掉，真正要看的欄位名反而找不到。
            extra = f"（{len(value)} 筆，內容另外印）"
        else:
            extra = f" = {value!r}"
        note = "" if seen[hit] == n else f"，只有 {seen[hit]}/{n} 筆有"
        print(f"      {label}：命中 {hit!r}（{kind}）{extra}{note}")


# 跟 transit_repository.dart 裡的欄位保持一致。
# **那邊改了這裡要一起改**，不然這支腳本就驗不到真正在跑的東西。
#
# 公車這一組 2026-09-03 已經對過真實回應，所以不再是「候選」而是確定的名字 ——
# 留在這裡是當回歸測試用的：哪天 TDX 改版把欄位換掉，這裡會直接標 [!]。
#
# 兩個踩過的坑，不要再踩回去：
#   - EstimateTime 是**選擇性欄位**，沒車的那幾筆連 key 都沒有。所以看到
#     「只有 1/15 筆有」是正常的，不是壞掉。
#   - StopCountDown **不是秒數，是還有幾站**（725 秒配 19 站）。
#     絕對不要把它加進「還有幾秒」的候選裡。
BUS_CANDIDATES = {
    "路線名": ["RouteName"],
    "還有幾秒": ["EstimateTime"],
    "站牌狀態": ["StopStatus"],
    "車牌": ["PlateNumb"],
    # 這個給的是 StopID（"306195"）不是站名，直接顯示會變成「往 306195」。
    # 要補成站名得另外查路線資料，那是還沒做的事。
    "終點站 ID（不是站名）": ["DestinationStop"],
    "還有幾站（不是秒）": ["StopCountDown"],
}

TRAIN_CANDIDATES = {
    "車次": ["TrainNo", "TrainNumber"],
    "車種": ["TrainTypeName", "TrainTypeCode"],
    "終點": ["EndingStationName", "DestinationStationName", "TripHeadSign"],
    "表定時間": [
        "ScheduledDepartureTime",
        "ScheduledArrivalTime",
        "DepartureTime",
    ],
    "誤點": ["DelayTime"],
}


# --------------------------------------------------------------- 查詢


def name_filter(template: str, names: list[str]) -> str:
    """把多個候選站名串成一條 OData filter。跟 Dart 那邊同一套。"""
    seen: list[str] = []
    for n in names:
        if n and n not in seen:
            seen.append(n)
    return " or ".join(template.replace("{name}", n.replace("'", "''")) for n in seen)


def all_names(stop: dict[str, Any]) -> list[str]:
    out = [stop.get("name", "")]
    if stop.get("station_name"):
        out.append(stop["station_name"])
    out.extend(stop.get("match_names", []))
    return [n for n in out if n]


def probe_bus(token: str, config: dict, stop: dict, *, save: bool) -> None:
    api = config["api"]
    intercity = stop["kind"] == "intercity_bus"
    path = (
        api["intercity_arrivals"]
        if intercity
        else api["city_bus_arrivals"].replace("{city}", stop.get("city", "Keelung"))
    )
    template = api["intercity_filter"] if intercity else api["city_bus_filter"]

    data = call(
        token,
        config,
        path,
        **{"$filter": name_filter(template, all_names(stop)), "$top": "60"},
    )
    if data is None:
        return

    rows, shape = unwrap(data)
    describe(rows, shape, BUS_CANDIDATES)

    if rows:
        # 站名到底長什麼樣 —— filter 用的名字對不對，看這裡最準。
        stop_names = {json.dumps(r.get("StopName"), ensure_ascii=False) for r in rows}
        print(f"  回來的站名：{', '.join(sorted(stop_names))}")
        routes = sorted({str(r.get("RouteName")) for r in rows})
        print(f"  經過的路線：{len(routes)} 條")
    else:
        print("  [!] 0 筆 —— filter 的欄位路徑可能不對（v3 也許把 StopName 扁平了），")
        print("      或這個站名在 TDX 裡叫別的名字。試試 --dump-stops。")

    if save:
        dump(f"{stop['id']}.json", data)


def probe_train(token: str, config: dict, stop: dict, *, save: bool) -> None:
    api = config["api"]

    station_id = stop.get("station_id", "")
    if not station_id:
        print("  station_id 是空的，先用站名查代碼……")
        data = call(
            token,
            config,
            api["train_stations"],
            **{
                "$filter": name_filter(api["train_station_filter"], all_names(stop)),
                "$top": "5",
            },
        )
        rows, shape = unwrap(data) if data is not None else ([], "")
        if not rows:
            print("  [!] 查不到車站。train_station_filter 的欄位路徑可能不對。")
            return
        for r in rows:
            print(f"      {r.get('StationID')} = {r.get('StationName')}")
        station_id = str(rows[0].get("StationID", ""))
        print(f"  >>> 把這個填回 transit.json 的 station_id：{station_id!r}")

    data = call(
        token,
        config,
        api["train_liveboard"],
        **{
            "$filter": api["train_liveboard_filter"].replace("{station}", station_id),
            "$top": "30",
        },
    )
    if data is None:
        return
    rows, shape = unwrap(data)
    describe(rows, shape, TRAIN_CANDIDATES)
    if save:
        dump(f"{stop['id']}.json", data)


def dump(name: str, data: Any) -> None:
    """把回應存成 fixture。

    TDX 的回應是**公開的公車與列車資訊，沒有任何個資** —— 跟 AIS 那邊的
    fixture 不同，這些可以直接進版控，拿來把 parser 的測試釘死。
    """
    FIXTURES.mkdir(parents=True, exist_ok=True)
    path = FIXTURES / name
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  存成 {path.relative_to(HERE.parent)}")


ROUTE_CANDIDATES = {
    "路線名": ["RouteName"],
    "去程終點": ["DestinationStopNameZh", "DestinationStopName", "DestinationStop"],
    "返程終點": ["DepartureStopNameZh", "DepartureStopName", "DepartureStop"],
}


def probe_routes(token: str, config: dict) -> None:
    """路線資料裡的終點站名叫什麼。

    到站端點只給 `DestinationStop`，而它是 StopID（`"306195"`）不是站名 ——
    直接顯示會變成「往 306195」。要補成站名就得從路線資料拿起訖站，
    而**這裡的欄位名一個都還沒驗證過**，所以先問清楚再寫進 Dart。

    只打兩個請求（市區 + 國道），因為上次連打六個就吃到 429。
    """
    api = config["api"]
    for label, path in (
        ("基隆市公車", api["city_bus_routes"].replace("{city}", "Keelung")),
        ("國道客運", api["intercity_routes"]),
    ):
        print()
        print(f"=== 路線資料：{label} ===")
        data = call(token, config, path, **{"$top": "30"})
        if data is None:
            continue
        rows, shape = unwrap(data)
        describe(rows, shape, ROUTE_CANDIDATES)
        if rows:
            # 到站資料裡的 RouteUID 要對得上這裡的 RouteUID，否則補不起來。
            print(f"  RouteUID 樣本：{[r.get('RouteUID') for r in rows[:3]]}")


def probe_direction(token: str, config: dict) -> None:
    """問死一件事：到站資料的 `Direction` 是 0 去程還是 1 返程。

    要把「往哪裡」補起來，得拿到站資料的 RouteUID 去路線資料查起訖站，
    再靠 `Direction` 決定要顯示哪一頭。TDX 的慣例是 0 去程 / 1 返程，
    **但這只是慣例，沒驗證過**。弄反了畫面會顯示一個看起來很合理的錯誤
    終點，使用者搭反方向 —— 沒有錯誤訊息，沒有人會發現。

    不用猜：到站資料裡的 `DestinationStop` 就是那班車真正的終點 StopID。
    把它解成站名，跟路線的兩端比一比，答案自己會跳出來。

    只打兩個請求，而且都帶 filter，不整包拉。
    """
    api = config["api"]
    runs: dict[tuple[str, int], str] = {}
    for f in sorted(FIXTURES.glob("*.json")):
        try:
            rows = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(rows, list):
            continue  # 台鐵那份是 v3 的物件，不是公車
        for r in rows:
            uid, dest = r.get("RouteUID"), r.get("DestinationStop")
            if uid and dest:
                runs[(uid, r.get("Direction", -1))] = dest

    if not runs:
        print("找不到公車 fixture。先跑 tdx.py --save。")
        return

    route_uids = sorted({uid for uid, _ in runs})
    stop_ids = sorted(set(runs.values()))
    print(f"從 fixture 撈到 {len(runs)} 組（路線, 方向），{len(route_uids)} 條路線")

    # 市區公車和國道客運是兩個端點，而 fixture 裡兩種路線都有
    # （KEE… 是基隆市公車，THB… 是國道客運）。**兩邊都要查再合併** ——
    # 只查市區的話 THB 那些會全部落空，而畫面上「查不到」跟「還沒實作」
    # 長得一樣，很容易誤判成 API 壞了。
    routes = _fetch_by(
        token, config, api["city_bus_routes"].replace("{city}", "Keelung"),
        "RouteUID", route_uids,
    ) + _fetch_by(token, config, api["intercity_routes"], "RouteUID", route_uids)
    # 站牌也要兩邊都查。**國道客運的站牌不在基隆市的站牌清單裡** ——
    # 它們散在台北、南投、台中。只查基隆的話那些 StopID 全部解不出名字，
    # 印出來是一整排「都不是」，看起來像慣例不成立，其實只是查錯地方。
    stops = _fetch_by(
        token, config, api["city_bus_stops"].replace("{city}", "Keelung"),
        "StopID", stop_ids,
    ) + _fetch_by(token, config, api["intercity_stops"], "StopID", stop_ids)

    names = {str(s.get("StopID")): _zh(s.get("StopName")) for s in stops}
    ends = {
        str(r.get("RouteUID")): (
            _zh(r.get("DepartureStopNameZh")),
            _zh(r.get("DestinationStopNameZh")),
        )
        for r in routes
    }

    print()
    print(f"  {'路線':10} {'方向':4} {'那班車的終點':18} {'起點欄位':18} 終點欄位")
    verdict: set[str] = set()
    for (uid, direction), dest_id in sorted(runs.items()):
        real = names.get(str(dest_id), f"(查不到 {dest_id})")
        dep, dst = ends.get(uid, ("(查不到)", "(查不到)"))
        hit = "終點欄位" if real == dst else "起點欄位" if real == dep else "都不是"
        verdict.add(f"{direction}->{hit}")
        print(f"  {uid:10} {direction:<4} {real:18} {dep:18} {dst}   <= {hit}")

    print()
    print(f"  結論：{sorted(verdict)}")
    print("  Direction 0 對到「終點欄位」= TDX 慣例成立，可以照著寫進 Dart。")


def _fetch_by(
    token: str, config: dict, path: str, field: str, values: list[str]
) -> list[dict]:
    """用 `field eq '值' or ...` 一次把要的幾筆抓回來。"""
    clause = " or ".join(f"{field} eq '{v}'" for v in values)
    data = call(token, config, path, **{"$filter": clause, "$top": "100"})
    if data is None:
        return []
    rows, _ = unwrap(data)
    return rows


def _zh(v: object) -> str:
    """多語系欄位或扁平字串 → 中文。跟 Dart 的 `_text` 同一套。"""
    if isinstance(v, str):
        return v
    if isinstance(v, dict):
        for k in ("Zh_tw", "ZhTw", "En"):
            got = v.get(k)
            if isinstance(got, str) and got:
                return got
    return ""


STOP_OF_ROUTE_CANDIDATES = {
    "路線名": ["RouteName"],
    "方向": ["Direction"],
    "站序陣列": ["Stops"],
}

REALTIME_CANDIDATES = {
    "車牌": ["PlateNumb"],
    "路線名": ["RouteName"],
    "方向": ["Direction"],
    "在第幾站": ["StopSequence"],
    "站牌": ["StopName", "StopUID"],
    "進站還離站": ["A2EventType"],
    "營運狀態": ["DutyStatus"],
}


def probe_route_detail(token: str, config: dict, route: str, *, save: bool) -> None:
    """點進一條路線要的兩份資料：站序、每台車現在在第幾站。

    這是「像 Bus+ 那樣顯示公車開到哪一站」需要的東西。跟到站時間不同，
    這兩個端點都還沒對過真實回應 —— 先問清楚欄位名再寫進 Dart。

    海大那三個站是基隆市公車，所以預設查基隆；`--route` 給的是路線名
    （`103`），不是 RouteUID。
    """
    api = config["api"]
    city = "Keelung"
    name_filter = api["route_name_filter"].replace("{name}", route.replace("'", "''"))

    print()
    print(f"=== 路線 {route} 的站序 ===")
    data = call(
        token,
        config,
        api["city_bus_stops_of_route"].replace("{city}", city),
        **{"$filter": name_filter},
    )
    if data is not None:
        rows, shape = unwrap(data)
        describe(rows, shape, STOP_OF_ROUTE_CANDIDATES)
        for r in rows:
            stops = r.get("Stops") or []
            # **子路線是關鍵。** 103 是環狀線，兩條站序都是 Direction 0 ——
            # 只靠方向配對即時位置會配到錯的那一條。分得出來的是 SubRouteUID。
            print(
                f"  子路線 {r.get('SubRouteUID')!r}"
                f"（{_zh(r.get('SubRouteName'))}）"
                f" 方向 {r.get('Direction')}：{len(stops)} 站"
            )
            if stops:
                print(f"    第一站的欄位：{', '.join(sorted(stops[0].keys()))}")
                head = " → ".join(_zh(x.get("StopName")) for x in stops[:4])
                tail = " → ".join(_zh(x.get("StopName")) for x in stops[-2:])
                print(f"    {head} … {tail}")
        if save:
            dump(f"route-{route}-stops.json", data)

    print()
    print(f"=== 路線 {route} 現在有幾台車、在哪 ===")
    data = call(
        token,
        config,
        api["city_bus_realtime"].replace("{city}", city),
        **{"$filter": name_filter},
    )
    if data is None:
        return
    rows, shape = unwrap(data)
    describe(rows, shape, REALTIME_CANDIDATES)
    if not rows:
        print("  （現在路上沒有這條路線的車 —— 深夜很正常，白天再跑一次）")
        return
    for r in rows:
        print(
            f"    {r.get('PlateNumb')}  子路線 {r.get('SubRouteUID')}  "
            f"方向 {r.get('Direction')}  第 {r.get('StopSequence')} 站"
            f"（{_zh(r.get('StopName'))}）  "
            f"A2EventType={r.get('A2EventType')}  DutyStatus={r.get('DutyStatus')}  "
            f"BusStatus={r.get('BusStatus')}"
        )
    if save:
        dump(f"route-{route}-realtime.json", data)


def dump_stops(token: str, config: dict) -> None:
    """把基隆市所有站名裡含「海大」或「海洋」的都印出來。

    站牌在 TDX 裡到底叫什麼名字，用這個查最快 —— 比猜快得多。
    """
    print("\n=== 基隆市含「海大 / 海洋」的站牌 ===")
    data = call(
        token,
        config,
        config["api"]["city_bus_stops"].replace("{city}", "Keelung"),
        **{"$filter": "contains(StopName/Zh_tw,'海大') or contains(StopName/Zh_tw,'海洋')"},
    )
    if data is None:
        return
    rows, _ = unwrap(data)
    seen = set()
    for r in rows:
        name = json.dumps(r.get("StopName"), ensure_ascii=False)
        if name not in seen:
            seen.add(name)
            print(f"  {r.get('StopUID', ''):20} {name}")
    if not rows:
        print("  [!] 0 筆 —— contains() 的欄位路徑可能不對。")


# --------------------------------------------------------------- main


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--save", action="store_true", help="把回應存成 fixture")
    ap.add_argument("--stop", help="只查這一站（用 transit.json 裡的 name）")
    ap.add_argument("--dump-stops", action="store_true", help="列出海大附近的站牌名")
    ap.add_argument(
        "--probe-routes",
        action="store_true",
        help="查路線資料的終點站名欄位（「往哪裡」那一欄還沒補起來）",
    )
    ap.add_argument(
        "--probe-direction",
        action="store_true",
        help="驗證 Direction 0/1 對應去程還是返程（用已存的 fixture 比對）",
    )
    ap.add_argument(
        "--probe-route-detail",
        metavar="路線名",
        help="查一條路線的站序與公車即時位置（例如 --probe-route-detail 103）",
    )
    args = ap.parse_args()

    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    print(f"設定：{CONFIG.relative_to(HERE.parent)}（version {config['version']}）")

    token = get_token(config)

    if args.dump_stops:
        dump_stops(token, config)
        return

    if args.probe_routes:
        probe_routes(token, config)
        return

    if args.probe_direction:
        probe_direction(token, config)
        return

    if args.probe_route_detail:
        probe_route_detail(token, config, args.probe_route_detail, save=args.save)
        return

    for stop in config["stops"]:
        if args.stop and stop["name"] != args.stop:
            continue
        print(f"\n=== {stop['name']}（{stop['kind']}）===")
        if stop["kind"] == "train":
            probe_train(token, config, stop, save=args.save)
        else:
            probe_bus(token, config, stop, save=args.save)

    print("\n完成。上面標 [!] 的地方就是 transit.json 或 repository 要改的地方。")


if __name__ == "__main__":
    main()
