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

/** 只讓這幾個查詢參數通過。其餘一律丟掉。 */
const ALLOWED_PARAMS = new Set(['$filter', '$top', '$format', '$select', '$orderby']);

/** 查詢字串長度上限。擋掉拿超長 filter 來繞過快取的玩法。 */
const MAX_QUERY_LENGTH = 2000;

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

    if (!ALLOWED_PREFIXES.some((p) => path.startsWith(p))) {
      // 刻意不說「哪些路徑可以」—— 那只是在幫想濫用的人省事。
      return json({ error: '這個路徑不開放' }, 404);
    }

    if (url.search.length > MAX_QUERY_LENGTH) {
      return json({ error: '查詢字串太長' }, 414);
    }

    if (!env.TDX_CLIENT_ID || !env.TDX_CLIENT_SECRET) {
      // 部署時忘記設 secret 是最容易發生的事，而且它跟「TDX 掛了」
      // 看起來一模一樣。講清楚是哪一種。
      return json({ error: '中繼服務尚未設定金鑰' }, 503);
    }

    const upstream = buildUpstreamUrl(path, url.searchParams);
    const cacheKey = new Request(upstream, { method: 'GET' });
    const cache = caches.default;

    const hit = await cache.match(cacheKey);
    if (hit) return withHeaders(hit, 'HIT');

    let res;
    try {
      res = await fetchFromTdx(upstream, env);
    } catch (e) {
      return json({ error: '連不上交通資料服務' }, 502);
    }

    if (!res.ok) {
      // **不要把 TDX 的回應原文往下傳。** 失敗的回應有可能把送出的參數回吐，
      // 而換 token 那個請求的 body 就是 client_secret 本人。
      const status = res.status === 429 ? 429 : 502;
      return json({ error: `交通資料服務回應 ${res.status}` }, status);
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

    // 寫快取不要擋著回應 —— 使用者等的是資料，不是我們的記帳。
    ctx.waitUntil(cache.put(cacheKey, cached.clone()));
    return withHeaders(cached, 'MISS');
  },
};

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
