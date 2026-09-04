import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'transit_models.dart';

/// `transit.json` 的型別化版本。
///
/// 跟 [SelectorConfig] 同一個用意，只是對象換成 TDX：**會因為對方改版而
/// 爛掉的字串一個都不寫在 Dart 裡**。端點路徑、站牌名、狀態碼對照全在 JSON。
///
/// 這件事在這裡比在 AIS 那邊更要緊 —— TDX 的公開 swagger 在 schema 那段是
/// 截斷的，沒有金鑰打不到真實回應。也就是說這份設定裡有幾個值是「照文件抄的，
/// 還沒對過真貨」。要能改一行 JSON 就修好，不要改一次程式送一次審。
class TransitConfig {
  const TransitConfig({
    required this.version,
    required this.tokenUrl,
    required this.renewMargin,
    required this.baseUrl,
    required this.relayBaseUrl,
    required this.minInterval,
    required this.timeout,
    required this.endpoints,
    required this.stopStatus,
    required this.stops,
  });

  final int version;

  /// OIDC token 端點。
  final String tokenUrl;

  /// token 提早多久換。
  ///
  /// TDX 的 token 給 86400 秒，但 token 端點每個 IP 每分鐘只准打 20 次。
  /// 卡在剛好過期才換的話，一旦時鐘有偏差就會連續失敗。提早換便宜得多。
  final Duration renewMargin;

  final String baseUrl;

  /// 中繼服務的網址。空字串代表直接打 TDX。
  ///
  /// 填了之後 App **不需要金鑰**，也不會撞到 429 —— 中繼那邊有快取，
  /// 而那五個站的資料對所有使用者都是同一份。公開發布走這條，
  /// 自己 build 來用可以留空直接打。服務本身在 `relay/`。
  final String relayBaseUrl;

  /// 現在是不是走中繼。
  bool get usesRelay => relayBaseUrl.isNotEmpty;

  /// 兩次請求之間至少隔多久。跟 AIS 那邊同樣的理由 —— 不要把對方打爛。
  /// TDX 的上限是每個 IP 每秒 50 次，離我們用的量很遠，但五個站點一次
  /// 重新整理就是五個請求，還是排隊送。
  final Duration minInterval;

  final Duration timeout;

  /// 端點路徑，`{city}` / `{station}` 是待代換的洞。
  final Map<String, String> endpoints;

  /// 公車 `StopStatus` 代碼 → 中文。認不得的代碼畫面上原樣顯示。
  final Map<String, String> stopStatus;

  final List<TransitStop> stops;

  static const String assetPath = 'assets/transit.json';

  /// 補上結尾的斜線。
  ///
  /// 設定檔是人寫的，少一條斜線的話網址會變成
  /// `https://relay.example.comv2/Bus/...` —— 那個錯誤在畫面上是
  /// 「連不上交通資料服務」，完全看不出是少了一個字元。
  static String _slashed(String url) {
    if (url.isEmpty) return '';
    return url.endsWith('/') ? url : '$url/';
  }

  static Future<TransitConfig> loadFromAsset() async {
    final raw = await rootBundle.loadString(assetPath);
    return TransitConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// 取一個端點，順便把洞填掉。
  ///
  /// 找不到 key 回傳空字串，呼叫端會當成「這個功能沒設定」而收起來 ——
  /// 比丟例外好：JSON 少一行不該讓整個分頁開不起來。
  String endpoint(String key, {String? city, String? station}) {
    var path = endpoints[key] ?? '';
    if (path.isEmpty) return '';
    if (city != null) path = path.replaceAll('{city}', city);
    if (station != null) path = path.replaceAll('{station}', station);
    return path;
  }

  factory TransitConfig.fromJson(Map<String, dynamic> json) {
    final auth = (json['auth'] as Map<String, dynamic>?) ?? const {};
    final api = (json['api'] as Map<String, dynamic>?) ?? const {};
    return TransitConfig(
      version: (json['version'] as num?)?.toInt() ?? 0,
      tokenUrl: auth['token_url'] as String? ??
          'https://tdx.transportdata.tw/auth/realms/TDXConnect'
              '/protocol/openid-connect/token',
      renewMargin: Duration(
        seconds: (auth['renew_margin_seconds'] as num?)?.toInt() ?? 600,
      ),
      baseUrl:
          api['base_url'] as String? ?? 'https://tdx.transportdata.tw/api/basic/',
      // build 時可以蓋過設定檔，方便指到測試用的中繼服務。
      relayBaseUrl: _slashed(
        const String.fromEnvironment('TDX_RELAY_URL').isNotEmpty
            ? const String.fromEnvironment('TDX_RELAY_URL')
            : (api['relay_base_url'] as String? ?? ''),
      ),
      minInterval: Duration(
        milliseconds:
            (((api['min_interval_seconds'] as num?) ?? 0.5) * 1000).round(),
      ),
      timeout: Duration(
        milliseconds: (((api['timeout_seconds'] as num?) ?? 15) * 1000).round(),
      ),
      endpoints: {
        for (final e in api.entries)
          // `_comment` / `_endpoints_comment` 是寫給人看的，不是端點
          if (!e.key.startsWith('_') && e.value is String) e.key: e.value as String,
      },
      stopStatus: {
        for (final e in
            ((json['stop_status'] as Map<String, dynamic>?) ?? const {}).entries)
          if (!e.key.startsWith('_') && e.value is String)
            e.key: e.value as String,
      },
      stops: [
        for (final s in (json['stops'] as List?) ?? const [])
          if (s is Map<String, dynamic>) TransitStop.fromJson(s),
      ],
    );
  }
}
