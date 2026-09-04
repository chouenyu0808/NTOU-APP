/**
 * TDX 中繼服務。
 *
 * ## 這東西是拿來解決什麼的
 *
 * App 原本直接打交通部的 TDX，金鑰用 `--dart-define` 編進 APK。自己一個人
 * 用沒問題，**但公開發布會壞在配額上，不是壞在保密上**：TDX 的速率限制綁在
 * 金鑰上，不是綁在使用者上。五百個學生共用同一把金鑰，每人每 30 秒 3 個
 * 請求，加起來每秒 50 個打在同一把金鑰上 —— 不用等到有人反編譯挖走金鑰，
 * 第一天就全部 429。
 *
 * 關鍵事實是：**那五個站的資料對所有使用者都是同一份。** 所以這裡抓一次、
 * 快取起來，不管有 5 個還是 5000 個使用者都回同一份 —— 打到 TDX 的請求量
 * 跟使用者數量完全無關，永遠是每 30 秒 3 個，比一個人直接用還少。
 *
 * ## 順帶解決的事
 *
 * - App 端不再需要金鑰，`--dart-define` 那套可以拿掉，也不會再有
 *   「漏帶參數就安靜變成『交通資訊還沒開通』」這個坑。
 * - 使用者不會再撞到 429，因為他們拿到的是快取。
 * - 交通那半邊本來就沒有個資（不用登入、站是寫死的），所以這個服務看得到的
 *   只有「有人打開了交通頁」，沒有任何值得保護的東西經過它。
 *
 * ## 部署
 *
 * 見 README.md。金鑰用 `wrangler secret put` 放進去，**不進版控**。
 */

/**
 * 准許轉發的路徑。
 *
 * **這個清單是安全邊界，不是方便性設定。** 沒有它的話這就是一個掛著你的
 * 金鑰的開放代理，任何人都能拿去打 TDX 的任意端點，配額照樣被吃光 ——
 * 那就等於什麼都沒解決。只放 App 真正會用到的。
 *
 * 比對方式是前綴，因為路徑尾巴帶著城市（`City/Keelung`）和車站代碼。
 */
const ALLOWED_PREFIXES = [
  'v2/Bus/EstimatedTimeOfArrival/City/',
  'v2/Bus/EstimatedTimeOfArrival/InterCity',
  'v2/Bus/Route/City/',
  'v2/Bus/Route/InterCity',
  'v2/Bus/Stop/City/',
  'v2/Bus/Stop/InterCity',
  'v2/Bus/StopOfRoute/City/',
  'v2/Bus/StopOfRoute/InterCity',
  'v2/Bus/RealTimeNearStop/City/',
  'v2/Bus/RealTimeNearStop/InterCity',
  'v3/Rail/TRA/StationLiveBoard',
  'v3/Rail/TRA/Station',
  'v3/Rail/TRA/DailyStationTimetable/',
];

/**
 * 快取多久（秒）。
 *
 * 30 秒不是隨便訂的：台鐵的回應外層自己帶著 `UpdateInterval: 30`、
 * `SrcUpdateInterval: 60` —— **資料在 TDX 端每 30 秒才換一次**。快取短於
 * 這個只會把同一份資料重抓幾次，畫面上的數字一個都不會提早變。
 *
 * 站序和路線資料一天才變一次，可以放很久。它們也是回應最大的（103 兩條
 * 子路線就 132 個站牌），快取久一點省最多。
 */
const TTL = [
  [/EstimatedTimeOfArrival/, 30],
  [/RealTimeNearStop/, 30],
  [/StationLiveBoard/, 30],
  [/StopOfRoute/, 21600], // 6 小時
  [/Bus\/Route/, 21600],
  [/Bus\/Stop/, 21600],
  [/Rail\/TRA\/Station$/, 86400], // 車站清單，一天
  [/DailyStationTimetable/, 3600],
];
const DEFAULT_TTL = 60;

/**
 * 備胎留多久（秒）。
 *
 * 十分鐘是刻意的：足夠撐過 TDX 一陣子的 429 或短暫故障，又不會久到
 * 讓人看著半小時前的公車時間還以為是即時的。超過這個就寧可報錯 ——
 * 太舊的資料比沒有資料更危險。
 */
const STALE_TTL = 600;

/** 只讓這幾個查詢參數通過。其餘一律丟掉。 */
const ALLOWED_PARAMS = new Set(['$filter', '$top', '$format', '$select', '$orderby']);

/** 查詢字串長度上限。擋掉拿超長 filter 來繞過快取的玩法。 */
const MAX_QUERY_LENGTH = 2000;

/**
 * `/batch` 一次最多問幾個。
 *
 * App 現在最多用到 3 個（基隆市公車、國道客運、台鐵）。留一點餘裕，
 * 但**一定要有上限** —— 沒有的話這就變成「一個請求打 N 個上游」的放大器。
 */
const MAX_BATCH = 6;

/**
 * token 放在 isolate 的記憶體裡。
 *
 * **不寫進任何快取。** 它是金鑰換來的東西，而 `caches.default` 是共用的邊緣
 * 快取，把 bearer token 放進去只是把一個秘密換個地方擺。
 *
 * 這樣做會不會一直重換？不會 —— 大部分請求根本命中快取、連 TDX 都不用打，
 * 也就不需要 token。真正要 token 的只有快取沒中的那幾次，全世界加起來
 * 每 30 秒 3 次。isolate 換掉就重換一張，那個成本可以忽略。
 */
let cachedToken = null;
let tokenExpiresAt = 0;

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'GET') {
      return json({ error: '只接受 GET' }, 405);
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, '');

    if (path === '' || path === 'health') {
      return json({ ok: true, service: 'ntou-app tdx relay' });
    }

    if (url.search.length > MAX_QUERY_LENGTH) {
      return json({ error: '查詢字串太長' }, 414);
    }

    if (!env.TDX_CLIENT_ID || !env.TDX_CLIENT_SECRET) {
      // 部署時忘記設 secret 是最容易發生的事，而且它跟「TDX 掛了」
      // 看起來一模一樣。講清楚是哪一種。
      return json({ error: '中繼服務尚未設定金鑰' }, 503);
    }

    if (path === 'batch') return serveBatch(url, env, ctx);

    if (!ALLOWED_PREFIXES.some((p) => path.startsWith(p))) {
      // 刻意不說「哪些路徑可以」—— 那只是在幫想濫用的人省事。
      return json({ error: '這個路徑不開放' }, 404);
    }

    const result = await serveOne(path, url.searchParams, env, ctx);
    return withHeaders(
      new Response(result.body, {
        status: result.status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': `public, max-age=${result.maxAge}`,
        },
      }),
      result.cache,
    );
  },
};

/**
 * 一次問好幾個端點。
 *
 * ## 為什麼要這個
 *
 * 桌面小組件每次更新要三份資料（基隆市公車、國道客運、台鐵），分開打就是
 * **三個 Worker 請求**。而小組件跟 App 不一樣 —— 它裝了就一直在背景更新，
 * 跟使用者有沒有在看無關。五百個人各裝一個、每 30 分鐘更新一次，
 * 一天就是七萬多個請求，逼近 Cloudflare 免費方案每天十萬的上限。
 *
 * 併成一個就降到兩萬四。
 *
 * ## 這不會增加打到 TDX 的量
 *
 * 每一份還是走 [serveOne]、用**同一組快取鍵** —— 所以 batch 和單獨查詢是
 * 共用快取的，打到 TDX 的請求量完全不變（還是每 30 秒 3 個）。
 * 這裡省的是 Worker 自己的請求數，不是 TDX 的。
 *
 * ## 格式
 *
 * `GET /batch?r=<路徑?查詢>&r=<...>`，每個 `r` 都是 URL 編碼過的。
 * 回應是 `{ results: [{ path, status, data }] }`，順序跟 `r` 一致。
 *
 * **一個失敗不會拖垮整批** —— 那是刻意的，跟 App 裡「一站失敗不影響其他站」
 * 同一個道理：台鐵掛了公車還是要能看。
 */
async function serveBatch(url, env, ctx) {
  const requests = url.searchParams.getAll('r');
  if (requests.length === 0) return json({ error: '沒有指定要問什麼' }, 400);
  if (requests.length > MAX_BATCH) {
    // 沒有上限的話這就變成一個「一個請求打 N 個上游」的放大器。
    return json({ error: `一次最多 ${MAX_BATCH} 個` }, 400);
  }

  const results = await Promise.all(
    requests.map(async (raw) => {
      const [rawPath, rawQuery] = raw.split('?');
      const path = (rawPath ?? '').replace(/^\/+/, '');
      if (!ALLOWED_PREFIXES.some((p) => path.startsWith(p))) {
        return { maxAge: 0, row: { path, status: 404, cache: 'MISS', data: null } };
      }
      const one = await serveOne(path, new URLSearchParams(rawQuery ?? ''), env, ctx);
      return {
        maxAge: one.maxAge,
        row: {
          path,
          status: one.status,
          cache: one.cache,
          // 這裡是**解析過的物件**不是字串。讓 App 端多做一次 JSON.parse
          // 沒有任何好處，而且巢狀字串很難除錯。
          data: one.status === 200 ? JSON.parse(one.body) : null,
        },
      };
    }),
  );

  // 整批的 max-age 取最短的那個。取最長的話，公車時間會被列車那份
  // 六小時的快取一起壓著不更新 —— 而畫面上完全看不出來。
  //
  // 有任何一個失敗（maxAge 0）就整批不要快取：**把一份缺了公車的結果
  // 快取起來，等於讓每個人都看到同一個破洞**，而下一個人來問的時候
  // TDX 可能早就好了。
  const maxAge = results.reduce((min, r) => Math.min(min, r.maxAge), DEFAULT_TTL);
  return new Response(JSON.stringify({ results: results.map((r) => r.row) }), {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': `public, max-age=${maxAge}`,
    },
  });
}

/**
 * 問一個端點。回 `{ status, body, maxAge, cache }`。
 *
 * 單獨查詢和 batch 都走這裡，所以兩條路**共用同一組快取鍵** ——
 * 分開實作的話同一份資料會被抓兩次，而這個服務存在的全部理由就是快取。
 */
async function serveOne(path, searchParams, env, ctx) {
  const upstream = buildUpstreamUrl(path, searchParams);
  const cacheKey = new Request(upstream, { method: 'GET' });
  const staleKey = new Request(`${upstream}&__stale=1`, { method: 'GET' });
  const cache = caches.default;

  const hit = await cache.match(cacheKey);
  if (hit) {
    return { status: 200, body: await hit.text(), maxAge: ttlFor(path), cache: 'HIT' };
  }

  let res = null;
  try {
    res = await fetchFromTdx(upstream, env);
  } catch (e) {
    res = null;
  }

  if (!res || !res.ok) {
    // **TDX 掛了或擋我們的時候，寧可給舊資料也不要給錯誤。**
    //
    // 公車還有幾分鐘這種東西，晚三十秒的版本仍然有用；一個錯誤訊息
    // 一點用都沒有。而 TDX 是會擋人的 —— 開發過程就撞過好幾次 429。
    const stale = await cache.match(staleKey);
    if (stale) {
      return { status: 200, body: await stale.text(), maxAge: 30, cache: 'STALE' };
    }

    // 真的什麼都沒有才報錯。**不要把 TDX 的回應原文往下傳** ——
    // 失敗的回應有可能把送出的參數回吐，而換 token 那個請求的 body
    // 就是 client_secret 本人。
    if (!res) {
      return { status: 502, body: JSON.stringify({ error: '連不上交通資料服務' }), maxAge: 0, cache: 'MISS' };
    }
    const status = res.status === 429 ? 429 : 502;
    return {
      status,
      body: JSON.stringify({ error: `交通資料服務回應 ${res.status}` }),
      maxAge: 0,
      cache: 'MISS',
    };
  }

  const ttl = ttlFor(path);
  const body = await res.text();
  const cached = new Response(body, {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      // 這一行同時控制邊緣快取和 App 端的 http 快取。
      'cache-control': `public, max-age=${ttl}`,
    },
  });

  // 存兩份：一份照正常 TTL（給命中用），一份放久一點當**備胎**。
  //
  // 為什麼要第二份：邊緣快取過期之後那筆就不見了，而「過期」跟「沒用」
  // 是兩回事 —— TDX 擋人的時候，一份三分鐘前的公車時間遠比一個錯誤有用。
  const backup = new Response(body, {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': `public, max-age=${STALE_TTL}`,
    },
  });

  // 寫快取不要擋著回應 —— 使用者等的是資料，不是我們的記帳。
  ctx.waitUntil(
    Promise.all([cache.put(cacheKey, cached.clone()), cache.put(staleKey, backup)]),
  );
  return { status: 200, body, maxAge: ttl, cache: 'MISS' };
}

/**
 * 把路徑和查詢參數組回 TDX 的網址。
 *
 * **參數是白名單過濾後重組的，不是把 `url.search` 原樣接上去。** 原樣接的話
 * 使用者多帶一個無意義的參數就會產生一個新的快取鍵，快取形同虛設 ——
 * 而快取正是這整個服務存在的理由。
 */
function buildUpstreamUrl(path, params) {
  const kept = new URLSearchParams();
  // 排序過再組，讓參數順序不同的同一個查詢命中同一份快取。
  const names = [...params.keys()].filter((k) => ALLOWED_PARAMS.has(k)).sort();
  for (const name of names) {
    kept.set(name, params.get(name));
  }
  kept.set('$format', 'JSON');
  return `https://tdx.transportdata.tw/api/basic/${path}?${kept.toString()}`;
}

function ttlFor(path) {
  for (const [pattern, seconds] of TTL) {
    if (pattern.test(path)) return seconds;
  }
  return DEFAULT_TTL;
}

async function fetchFromTdx(upstream, env) {
  const token = await accessToken(env);
  return fetch(upstream, {
    headers: {
      authorization: `Bearer ${token}`,
      'accept-encoding': 'gzip',
    },
  });
}

async function accessToken(env) {
  const now = Date.now();
  if (cachedToken && now < tokenExpiresAt) return cachedToken;

  const res = await fetch(
    'https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token',
    {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: env.TDX_CLIENT_ID,
        client_secret: env.TDX_CLIENT_SECRET,
      }),
    },
  );

  if (!res.ok) {
    // 同樣不看回應內容 —— 這個請求的 body 就是 client_secret。
    throw new Error(`token ${res.status}`);
  }

  const body = await res.json();
  cachedToken = body.access_token;
  // TDX 給 86400 秒。提早 10 分鐘換掉，時鐘有偏差也不會卡在剛好過期。
  tokenExpiresAt = now + ((body.expires_in ?? 86400) - 600) * 1000;
  return cachedToken;
}

function withHeaders(res, cacheStatus) {
  const out = new Response(res.body, res);
  out.headers.set('x-relay-cache', cacheStatus);
  return out;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}
