import 'page.dart';

/// 所有 AIS 層的錯誤都帶一句可以直接顯示給使用者的中文。
///
/// 這個系統的失敗全都是靜默的（狀態碼 200、沒有錯誤訊息、頁面看起來很正常），
/// 所以「翻譯成人話」是這一層的責任，不是 UI 的責任。
abstract class AisException implements Exception {
  const AisException(this.message);

  /// 直接可以顯示給使用者看的訊息。
  final String message;

  @override
  String toString() => message;
}

/// 登入失敗。
///
/// **刻意不帶 page。** spike 的 `LoginFailed(msg, page)` 把登入回應掛在例外上，
/// 在 CLI 上很方便 debug。但 App 裡例外會往上飄 —— Flutter 的
/// `FlutterError.onError`、Zone 的 uncaught handler、任何崩潰回報 SDK
/// 都會把 `toString()` 收走。而登入回應**含兩次明文密碼**（見 spike/README 第一節）。
///
/// 需要 debug 的時候用 [diagnostics]：只有狀態碼、長度、有沒有導向指令，
/// 足夠判斷「是驗證碼錯還是密碼錯」，但沒有任何一個 byte 是頁面內容。
class LoginFailed extends AisException {
  const LoginFailed(super.message, {this.diagnostics = ''});

  final String diagnostics;
}

/// session 出問題：逾時被踢回登入頁，或帳號在別處還登著。
///
/// 這個帶 page 是安全的 —— 會走到這裡的都是功能頁，不是登入回應。
class SessionExpired extends AisException {
  const SessionExpired(super.message, {this.page});

  final AisPage? page;
}

/// 連線層的失敗（TLS、逾時、斷線）。
class NetworkFailure extends AisException {
  const NetworkFailure(super.message);
}

/// 送出的值不是頁面上真的有的選項。
///
/// ASP.NET 的 event validation 會拒絕它沒渲染過的值，但錯誤長成
/// 「系統發生錯誤, 請通知系統管理人員」—— 看不出是哪個欄位。在本機擋下來。
class InvalidFieldValue extends AisException {
  const InvalidFieldValue(super.message);
}
