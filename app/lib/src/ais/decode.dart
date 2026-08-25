import 'dart:convert';

final RegExp _metaCharsetRe = RegExp('charset=["\']?\\s*([\\w-]+)');

/// 從回應開頭的 meta 標籤讀宣告的編碼。HTTP header 不一定講實話，meta 通常有。
String? sniffCharset(List<int> bytes) {
  final head = latin1
      .decode(bytes.take(2048).toList(), allowInvalid: true)
      .toLowerCase();
  return _metaCharsetRe.firstMatch(head)?.group(1);
}

/// 解碼回應。
///
/// 台灣的舊 WebForms 站很多是 Big5，所以 spike 的 `_decode()` 準備了
/// utf-8 / big5-hkscs / cp950 三段 fallback。**但 AIS 實際上是 UTF-8** ——
/// 抓下來的 fixture 每一份的 meta 都是 `charset=utf-8`
/// （`test/charset_assumption_test.dart` 把這個假設鎖住了）。
///
/// Dart 內建只有 utf8 / latin1，加 Big5 codec 要多拉一個套件。
/// 既然證據說用不到，就不先付那個成本 —— 但假設破掉時要**看得見**，
/// 所以遇到不認得的編碼會丟 [UnsupportedCharset]，而不是安靜地解出一頁亂碼。
String decodeHtml(List<int> bytes) {
  final declared = sniffCharset(bytes)?.toLowerCase();
  if (declared == null || declared == 'utf-8' || declared == 'utf8') {
    // allowMalformed：頁面中途截斷時寧可顯示 U+FFFD，也不要整個 App 掛掉
    return utf8.decode(bytes, allowMalformed: true);
  }
  if (declared == 'iso-8859-1' || declared == 'latin1' || declared == 'ascii') {
    return latin1.decode(bytes, allowInvalid: true);
  }
  throw UnsupportedCharset(declared);
}

/// 學校把頁面編碼換成 Dart 內建解不了的東西（多半是 Big5）。
class UnsupportedCharset implements Exception {
  const UnsupportedCharset(this.charset);

  final String charset;

  @override
  String toString() =>
      '頁面編碼是 $charset，這個版本只支援 UTF-8。學校改了編碼，App 要更新。';
}
