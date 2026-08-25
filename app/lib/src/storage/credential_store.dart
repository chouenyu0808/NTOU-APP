import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 學號與密碼的保管處。
///
/// **這是整個 App 的架構紅線所在。** 密碼只存在裝置的 Keychain / Keystore，
/// 爬蟲跑在裝置端 —— 密碼永遠不經過任何我們自己的伺服器。
/// 一旦經過，就是在替全校學生保管帳密，出事自己扛。
///
/// iOS 那兩個參數是安全性選擇，不是照抄範例：
///   - `synchronizable: false` —— **不同步到 iCloud Keychain**。
///     同步等於把學校密碼複製到 Apple 的伺服器和使用者的每一台裝置。
///     這是套件的預設值，但明寫出來，免得哪天預設變了沒人發現。
///   - `first_unlock_this_device` —— 只有這支手機解鎖過才讀得到，
///     而且不會跟著 iCloud 備份還原到別台裝置。
///
/// Android 用套件 11.x 的預設：Keystore 包的 RSA-OAEP + AES-GCM。
/// （舊版要自己開 `encryptedSharedPreferences`，11.x 之後沒有明文那條路了。）
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
                synchronizable: false,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _kUsername = 'ntou.username';
  static const _kPassword = 'ntou.password';

  Future<String?> readUsername() => _storage.read(key: _kUsername);

  /// 讀密碼。**呼叫端不要把回傳值放進任何 log 或錯誤訊息。**
  Future<String?> readPassword() => _storage.read(key: _kPassword);

  Future<void> saveUsername(String username) =>
      _storage.write(key: _kUsername, value: username);

  /// 存密碼。只在使用者明確勾「記住密碼」時才呼叫。
  Future<void> savePassword(String password) =>
      _storage.write(key: _kPassword, value: password);

  Future<void> clearPassword() => _storage.delete(key: _kPassword);

  /// 完全登出：學號和密碼都清掉。
  Future<void> clearAll() async {
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kPassword);
  }
}
