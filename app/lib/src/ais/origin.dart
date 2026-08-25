const Map<String, int> _defaultPorts = {'http': 80, 'https': 443};

/// (scheme, host, port)，預設埠正規化 —— `https://x` 和 `https://x:443` 是同源。
String _origin(Uri u) {
  final port = u.hasPort ? u.port : (_defaultPorts[u.scheme] ?? 0);
  return '${u.scheme}://${u.host.toLowerCase()}:$port';
}

/// 導向目標是不是還在同一個站台。
///
/// **必要防護，不是防禦性程式設計的裝飾。** `MenuTree.aspx` 裡有一行
/// `top.mainFrame.location.href = "//portal.aspx"` —— 校方少打一條斜線，
/// 本意是 `/portal.aspx`。但 `//portal.aspx` 是協定相對 URL，
/// 解析出來是 `https://portal.aspx`，**一個站外主機**。
/// 自動跟隨就會把帶著 session cookie 的請求送出去，而那個網域誰都能註冊。
bool sameOrigin(Uri a, Uri b) => _origin(a) == _origin(b);
